#!/usr/bin/env bash
set -euo pipefail

INDEX_FILE="${1:-Index.html}"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "ERROR: $INDEX_FILE not found."
  echo "Run this from the Fixxir repo root."
  exit 1
fi

cp "$INDEX_FILE" "${INDEX_FILE}.before-repair-edit-fix.bak"

python3 - "$INDEX_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

start = html.find("function openRepairEdit()")
if start < 0:
    raise SystemExit("ERROR: Could not find openRepairEdit().")

next_candidates = [
    html.find("function repairEditStatusChanged()", start),
    html.find("async function submitRepairEdit", start),
    html.find("function submitRepairEdit", start),
]
next_candidates = [x for x in next_candidates if x > start]

if not next_candidates:
    raise SystemExit("ERROR: Could not find the end of openRepairEdit().")

end = min(next_candidates)

replacement = r'''function openRepairEdit() {
        if (!CURRENT_REPAIR) return;

        const r = CURRENT_REPAIR.repair || {};

        const form = document.getElementById("repairEditForm");
        if (!form) {
          toast("Repair edit form is unavailable. Refresh the app.", true);
          return;
        }

        form.reset();

        const setValue = (id, value) => {
          const el = document.getElementById(id);
          if (el) el.value = value ?? "";
        };

        const setText = (id, value) => {
          const el = document.getElementById(id);
          if (el) el.textContent = value ?? "";
        };

        setValue("editRepairId", r.Repair_ID || "");
        setText("repairEditTitle", `Edit ${r.Repair_ID || ""}`);

        fillSelect(
          "editRepairTechnician",
          (BOOT.technicians || []).map((t) => ({
            value: t.Technician_ID,
            label: t.Full_Name,
          })),
          "Unassigned",
        );

        fillSelect(
          "editRepairStatus",
          BOOT.settings.Repair_Status || [],
          "Select status",
        );

        fillSelect(
          "editRepairQA",
          BOOT.settings.QA_Status || [],
          "Select QA status",
        );

        setValue("editRepairTechnician", r.Technician_ID || "");
        setValue("editRepairStatus", r.Repair_Status || "");

        setText(
          "editRepairDateView",
          dateOnly(r.Repair_Date || r.Date_Received) || "—",
        );

        setValue(
          "editRepairFinal",
          r.Final_Amount === null || r.Final_Amount === undefined
            ? ""
            : r.Final_Amount,
        );

        setValue("editRepairQA", r.QA_Status || "");
        setValue("editRepairCompleted", dateOnly(r.Date_Completed));
        setValue("editRepairDiagnosis", r.Diagnosis || "");
        setValue("editRepairQANotes", r.QA_Notes || "");

        document.getElementById("repairEditModal")?.classList.add("open");
      }

      '''

html = html[:start] + replacement + html[end:]

check_start = html.find("function openRepairEdit()")
check_end_candidates = [
    html.find("function repairEditStatusChanged()", check_start),
    html.find("async function submitRepairEdit", check_start),
    html.find("function submitRepairEdit", check_start),
]
check_end_candidates = [x for x in check_end_candidates if x > check_start]
check_end = min(check_end_candidates) if check_end_candidates else check_start + 5000
region = html[check_start:check_end]

for forbidden in [
    'getElementById("editRepairDate")',
    "getElementById('editRepairDate')",
    'getElementById("editRepairNotes")',
    "getElementById('editRepairNotes')",
]:
    if forbidden in region:
        raise SystemExit(
            "ERROR: Obsolete repair edit reference still present: " + forbidden
        )

path.write_text(html, encoding="utf-8")
PY

echo
echo "Repair Edit button fix applied."
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- Index.html"
echo
echo "Then deploy:"
echo "  npm run deploy"
