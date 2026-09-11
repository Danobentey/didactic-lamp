#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Fixxir - One-time repository cleanup
# ==========================================================

echo
echo "======================================================"
echo " Fixxir Repository Cleanup"
echo "======================================================"
echo

# Ensure ignore rules exist.
touch .gitignore

add_ignore_rule() {
  local rule="$1"
  if ! grep -Fxq "$rule" .gitignore; then
    printf '%s\n' "$rule" >> .gitignore
  fi
}

add_ignore_rule "/node_modules"
add_ignore_rule ".DS_Store"
add_ignore_rule "*.bak"
add_ignore_rule "*.patch"
add_ignore_rule ".clasprc.json"
add_ignore_rule ".env"

# Stop tracking accidental local artifacts, but preserve local copies.
git rm --cached --ignore-unmatch \
  .DS_Store \
  Index.html.before-repair-edit.bak \
  fixxir-repair-edit.patch

git add .gitignore

echo
echo "Pending cleanup changes:"
git status --short
echo

read -r -p "Commit this repository cleanup? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Cleanup changes are staged but not committed."
  exit 0
fi

git commit -m "Chore: ignore local deployment artifacts"

echo
echo "Repository cleanup committed."
echo
echo "The local .DS_Store, .bak and .patch files are preserved,"
echo "but Git will no longer track them."
