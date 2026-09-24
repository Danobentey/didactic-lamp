#!/usr/bin/env bash
set -euo pipefail

CODE_FILE="${1:-Code.js}"
MANIFEST_FILE="${2:-appsscript.json}"

for f in "$CODE_FILE" "$MANIFEST_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f not found."; exit 1; }
done

if grep -q 'FIXXIR_PER_USER_AUDIT_V1' "$CODE_FILE"; then
  echo "Per-user audit identity patch already applied."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-per-user-audit-v1.bak"
cp "$MANIFEST_FILE" "${MANIFEST_FILE}.before-per-user-audit-v1.bak"

python3 - "$CODE_FILE" "$MANIFEST_FILE" <<'PY'
from pathlib import Path
import json, re, sys

code_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

webapp = manifest.setdefault("webapp", {})
webapp["executeAs"] = "USER_ACCESSING"
webapp.setdefault("access", "ANYONE")

manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

pattern = re.compile(
    r'function\s+currentUser_\s*\(\s*\)\s*\{.*?\n\}\s*(?=\nfunction\s+requireFields_)',
    re.S,
)
m = pattern.search(code)
if not m:
    raise SystemExit("ERROR: Could not safely locate currentUser_().")

replacement = '''/* FIXXIR_PER_USER_AUDIT_V1 */

function currentUser_() {
  const email = String(Session.getActiveUser().getEmail() || "")
    .trim()
    .toLowerCase();

  if (!email) {
    throw new Error(
      "Fixxir could not identify the signed-in user. " +
      "Sign in with an authorized Google account and reopen the app."
    );
  }

  return email;
}

function getCurrentUserIdentity() {
  assertAuthorized_();
  return {
    email: currentUser_(),
    effectiveUser: String(Session.getEffectiveUser().getEmail() || "")
      .trim()
      .toLowerCase()
  };
}
'''

code = code[:m.start()] + replacement + code[m.end():]

if "ensureAuditIdentitySchema_(ss);" not in code:
    anchor = "  const requiredSheets = Object.values(FIXXIR.sheets);\n"
    if anchor not in code:
        raise SystemExit("ERROR: Could not find initializeFixxir() anchor.")
    code = code.replace(anchor, "  ensureAuditIdentitySchema_(ss);\n\n" + anchor, 1)

if "function ensureAuditIdentitySchema_(ss)" not in code:
    anchor = "/* ---------------- Data helpers ---------------- */\n"
    if anchor not in code:
        raise SystemExit("ERROR: Could not find Data helpers anchor.")

    helper = '''/* ---------------- Audit identity schema ---------------- */

function ensureAuditIdentitySchema_(ss) {
  ss = ss || getSpreadsheet_();

  [
    [FIXXIR.sheets.repairs, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.purchases, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.salesOrders, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.quotes, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.catalog, ["Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.supplierCatalog, ["Last_Updated", "Last_Updated_By"]]
  ].forEach(([sheetName, headers]) => {
    if (sheetName) ensureSheetColumns_(ss, sheetName, headers);
  });
}

'''
    code = code.replace(anchor, helper + anchor, 1)

code = re.sub(
    r'(?m)^([ \t]*)Last_Updated:\s*now,\s*$',
    r'\1Last_Updated: now,\n\1Last_Updated_By: currentUser_(),',
    code,
)

code = re.sub(
    r'(?m)^([ \t]*)Last_Updated:\s*new Date\(\),\s*$',
    r'\1Last_Updated: new Date(),\n\1Last_Updated_By: currentUser_(),',
    code,
)

if "  updates.Last_Updated = new Date();\n" in code and "updates.Last_Updated_By = currentUser_();" not in code:
    code = code.replace(
        "  updates.Last_Updated = new Date();\n",
        "  updates.Last_Updated = new Date();\n  updates.Last_Updated_By = currentUser_();\n",
        1,
    )

current_start = code.find("function currentUser_()")
current_end = code.find("function getCurrentUserIdentity()", current_start)
if current_start < 0 or current_end < 0:
    raise SystemExit("ERROR: Audit identity functions missing after patch.")

if "getEffectiveUser" in code[current_start:current_end]:
    raise SystemExit("ERROR: currentUser_ still contains getEffectiveUser fallback.")

for needle in [
    "FIXXIR_PER_USER_AUDIT_V1",
    "function ensureAuditIdentitySchema_(ss)",
    "Last_Updated_By",
]:
    if needle not in code:
        raise SystemExit("ERROR: Code validation failed: " + needle)

code_path.write_text(code, encoding="utf-8")
PY

echo
echo "Fixxir per-user audit identity patch applied."
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- $CODE_FILE $MANIFEST_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "Each staff member must open the app using their own Google account"
echo "and complete Google's authorization prompt."
echo
echo "Optional identity test from Apps Script:"
echo "  getCurrentUserIdentity()"
