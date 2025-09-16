#!/usr/bin/env bash
set -euo pipefail

# Minimal mandatory extensions for Wookieepedia content rendering.
BRANCH=REL1_41
EXT_DIR="/var/www/html/extensions"
MANDATORY=(ParserFunctions Scribunto Cite TemplateStyles ImageMap Interwiki PortableInfobox)

grab() {
  local name="$1"
  local repo
  if [ "$name" = "PortableInfobox" ]; then
    # PortableInfobox lives in a different GitHub repo (Universal-Omega fork for REL1_41 support)
    repo="https://github.com/Universal-Omega/PortableInfobox.git"
  else
    repo="https://gerrit.wikimedia.org/r/mediawiki/extensions/${name}.git"
  fi
  if [ ! -d "${EXT_DIR}/${name}" ]; then
    echo "Cloning ${name}" >&2
    git clone --depth 1 -b "$BRANCH" "$repo" "${EXT_DIR}/${name}" || { echo "Failed to clone $name from $repo" >&2; exit 1; }
    rm -rf "${EXT_DIR}/${name}/.git" || true
  fi
}

for e in "${MANDATORY[@]}"; do
  grab "$e"
done

echo "Mandatory extensions present." >&2
