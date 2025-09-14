#!/usr/bin/env bash
set -euo pipefail

# Minimal mandatory extensions for Wookieepedia content rendering.
BRANCH=REL1_41
EXT_DIR="/var/www/html/extensions"
MANDATORY=(ParserFunctions Scribunto Cite TemplateStyles ImageMap Interwiki)

grab() {
  local name="$1"
  local repo="https://gerrit.wikimedia.org/r/mediawiki/extensions/${name}.git"
  if [ ! -d "${EXT_DIR}/${name}" ]; then
    echo "Cloning ${name}" >&2
  git clone --depth 1 -b "$BRANCH" "$repo" "${EXT_DIR}/${name}" || { echo "Failed to clone $name from Gerrit" >&2; exit 1; }
    rm -rf "${EXT_DIR}/${name}/.git"
  fi
}

for e in "${MANDATORY[@]}"; do
  grab "$e"
done

echo "Mandatory extensions present." >&2
