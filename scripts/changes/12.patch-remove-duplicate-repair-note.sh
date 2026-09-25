#!/usr/bin/env bash
set -euo pipefail

INDEX_FILE="${1:-Index.html}"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "ERROR: $INDEX_FILE not found."
  echo "Run this from the Fixxir repo root."
  exit 1
fi

cp "$INDEX_FILE" "${INDEX_FILE}.before-remove-duplicate-repair-note.bak"

python3 - "$INDEX_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

# Remove only the first/larger Repair '+ Add Note' button from the repair
# action row. Keep the smaller '+ Add Note' button beside the Notes heading.
patterns = [
    r'''\s*<button\b[^>]*class=["'][^"']*btn[^"']*["'][^>]*onclick=["']openEntityNote\(\s*['"]Repair['"][^)]*\)["'][^>]*>\s*\+\s*Add Note\s*</button>''',
    r'''\s*<button\b[^>]*onclick=["']openEntityNote\(\s*['"]Repair['"][^)]*\)["'][^>]*class=["'][^"']*btn[^"']*["'][^>]*>\s*\+\s*Add Note\s*</button>''',
]

removed = False

for pattern in patterns:
    matches = list(re.finditer(pattern, html, flags=re.I | re.S))
    if matches:
        m = matches[0]
        html = html[:m.start()] + html[m.end():]
        removed = True
        break

if not removed:
    raise SystemExit(
        "ERROR: Could not find the larger Repair '+ Add Note' button."
    )

# Confirm at least one Repair Add Note control remains.
remaining = re.findall(
    r'''openEntityNote\(\s*['"]Repair['"]''',
    html,
    flags=re.I,
)

if not remaining:
    raise SystemExit(
        "ERROR: Patch would remove all Repair Add Note controls; nothing written."
    )

path.write_text(html, encoding="utf-8")
PY

echo
echo "Removed the duplicate large Repair '+ Add Note' button."
echo "The smaller '+ Add Note' button beside the Notes section remains."
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- Index.html"
echo
echo "Then deploy:"
echo "  npm run deploy"
