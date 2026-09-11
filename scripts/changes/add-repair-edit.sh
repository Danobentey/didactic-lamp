#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Fixxir Operations - Add Repair Edit Workflow
# ==========================================================
#
# Adds an Edit Repair modal/UI to Index.html.
# The Apps Script backend already exposes updateRepair(),
# so Code.js does not need to change for this feature.
#
# Safe to run more than once:
# - If the feature is already present, the script exits cleanly.
# - If the expected source anchors cannot be found, it aborts
#   instead of making a partial/incorrect edit.
# ==========================================================

TARGET_FILE="${1:-Index.html}"

echo
echo "======================================================"
echo " Fixxir - Add Repair Edit Workflow"
echo "======================================================"
echo

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "ERROR: $TARGET_FILE not found."
  echo "Run this script from the repository root, or pass the file path:"
  echo "  $0 path/to/Index.html"
  exit 1
fi

if grep -q 'id="repairEditModal"' "$TARGET_FILE"; then
  echo "Repair edit workflow is already present in $TARGET_FILE."
  echo "No changes made."
  exit 0
fi

BACKUP_FILE="${TARGET_FILE}.before-repair-edit.bak"
cp "$TARGET_FILE" "$BACKUP_FILE"

echo "Backup created:"
echo "  $BACKUP_FILE"
echo

python3 - "$TARGET_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

modal_anchor = '''<div class="modal" id="repairDetailModal">
  <div class="modal-box" style="width:min(1050px,100%)">
    <div class="modal-head"><h3 id="repairDetailTitle">Repair</h3><button class="close" onclick="closeModal('repairDetailModal')">×</button></div>
    <div class="modal-body" id="repairDetailBody"></div>
  </div>
</div>

<div class="modal" id="financeModal">'''

modal_replacement = '''<div class="modal" id="repairDetailModal">
  <div class="modal-box" style="width:min(1050px,100%)">
    <div class="modal-head"><h3 id="repairDetailTitle">Repair</h3><button class="close" onclick="closeModal('repairDetailModal')">×</button></div>
    <div class="modal-body" id="repairDetailBody"></div>
  </div>
</div>

<div class="modal" id="repairEditModal">
  <div class="modal-box" style="width:min(850px,100%)">
    <div class="modal-head">
      <h3 id="repairEditTitle">Edit Repair</h3>
      <button class="close" onclick="closeModal('repairEditModal')">×</button>
    </div>

    <form id="repairEditForm" onsubmit="submitRepairEdit(event)">
      <div class="modal-body">
        <input type="hidden" name="Repair_ID" id="editRepairId">

        <div class="form-grid">
          <div>
            <label>Technician</label>
            <select class="select" name="Technician_ID" id="editRepairTechnician"></select>
          </div>

          <div>
            <label>Status</label>
            <select class="select" name="Repair_Status" id="editRepairStatus"></select>
          </div>

          <div>
            <label>Priority</label>
            <select class="select" name="Priority" id="editRepairPriority"></select>
          </div>

          <div>
            <label>Expected completion</label>
            <input class="input" type="date" name="Expected_Completion" id="editRepairExpected">
          </div>

          <div>
            <label>Quoted amount (₦)</label>
            <input class="input" type="number" min="0" step="1" name="Quoted_Amount" id="editRepairQuoted">
          </div>

          <div>
            <label>Final amount (₦)</label>
            <input class="input" type="number" min="0" step="1" name="Final_Amount" id="editRepairFinal">
          </div>

          <div>
            <label>QA status</label>
            <select class="select" name="QA_Status" id="editRepairQA"></select>
          </div>

          <div>
            <label>Warranty days</label>
            <input class="input" type="number" min="0" name="Warranty_Days" id="editRepairWarranty">
          </div>

          <div>
            <label>Collection method</label>
            <select class="select" name="Collection_Method" id="editRepairCollection">
              <option value="">Select</option>
              <option>Pickup</option>
              <option>Delivery</option>
              <option>Courier</option>
              <option>Other</option>
            </select>
          </div>

          <div>
            <label>Date completed</label>
            <input class="input" type="date" name="Date_Completed" id="editRepairCompleted">
          </div>

          <div class="full">
            <label>Diagnosis</label>
            <textarea class="textarea" name="Diagnosis" id="editRepairDiagnosis"></textarea>
          </div>

          <div class="full">
            <label>QA notes</label>
            <textarea class="textarea" name="QA_Notes" id="editRepairQANotes"></textarea>
          </div>

          <div class="full">
            <label>Notes</label>
            <textarea class="textarea" name="Notes" id="editRepairNotes"></textarea>
          </div>
        </div>
      </div>

      <div class="modal-foot">
        <button type="button" class="btn" onclick="closeModal('repairEditModal')">Cancel</button>
        <button class="btn primary" type="submit">Save changes</button>
      </div>
    </form>
  </div>
</div>

<div class="modal" id="financeModal">'''

if modal_anchor not in text:
    raise SystemExit(
        "ERROR: Could not find the repair detail/finance modal anchor. "
        "Index.html may have changed. No source file was written."
    )

text = text.replace(modal_anchor, modal_replacement, 1)

button_anchor = '''          <div style="margin-top:18px;display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn primary" onclick="openFinanceForRepair('Credit')">+ Customer Payment</button>
            <button class="btn" onclick="openFinanceForRepair('Debit')">+ Repair Expense</button>
          </div>'''

button_replacement = '''          <div style="margin-top:18px;display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn dark" onclick="openRepairEdit()">Edit Repair</button>
            <button class="btn primary" onclick="openFinanceForRepair('Credit')">+ Customer Payment</button>
            <button class="btn" onclick="openFinanceForRepair('Debit')">+ Repair Expense</button>
          </div>'''

if button_anchor not in text:
    raise SystemExit(
        "ERROR: Could not find the repair action-button anchor. "
        "Index.html may have changed. No source file was written."
    )

text = text.replace(button_anchor, button_replacement, 1)

js_anchor = '''  function detail(label,value){return `<div class="detail-item"><div class="label">${esc(label)}</div><div class="value">${value}</div></div>`}'''

js_insert = r'''  function openRepairEdit(){
    if(!CURRENT_REPAIR) return;

    const r = CURRENT_REPAIR.repair;

    document.getElementById('repairEditForm').reset();
    document.getElementById('editRepairId').value = r.Repair_ID || '';
    document.getElementById('repairEditTitle').textContent = `Edit ${r.Repair_ID}`;

    fillSelect(
      'editRepairTechnician',
      BOOT.technicians.map(t => ({
        value: t.Technician_ID,
        label: t.Full_Name
      })),
      'Unassigned'
    );

    fillSelect(
      'editRepairStatus',
      BOOT.settings.Repair_Status || [],
      'Select status'
    );

    fillSelect(
      'editRepairPriority',
      BOOT.settings.Priority || [],
      'Select priority'
    );

    fillSelect(
      'editRepairQA',
      BOOT.settings.QA_Status || [],
      'Select QA status'
    );

    document.getElementById('editRepairTechnician').value = r.Technician_ID || '';
    document.getElementById('editRepairStatus').value = r.Repair_Status || '';
    document.getElementById('editRepairPriority').value = r.Priority || '';
    document.getElementById('editRepairExpected').value = dateOnly(r.Expected_Completion);
    document.getElementById('editRepairQuoted').value =
      r.Quoted_Amount === null || r.Quoted_Amount === undefined ? '' : r.Quoted_Amount;
    document.getElementById('editRepairFinal').value =
      r.Final_Amount === null || r.Final_Amount === undefined ? '' : r.Final_Amount;
    document.getElementById('editRepairQA').value = r.QA_Status || '';
    document.getElementById('editRepairWarranty').value =
      r.Warranty_Days === null || r.Warranty_Days === undefined ? '' : r.Warranty_Days;
    document.getElementById('editRepairCollection').value = r.Collection_Method || '';
    document.getElementById('editRepairCompleted').value = dateOnly(r.Date_Completed);
    document.getElementById('editRepairDiagnosis').value = r.Diagnosis || '';
    document.getElementById('editRepairQANotes').value = r.QA_Notes || '';
    document.getElementById('editRepairNotes').value = r.Notes || '';

    document.getElementById('repairEditModal').classList.add('open');
  }

  async function submitRepairEdit(e){
    e.preventDefault();

    const data = formObject(e.target);

    showLoading(true);

    try {
      CURRENT_REPAIR = await server('updateRepair', data);

      closeModal('repairEditModal');
      renderRepairDetail(CURRENT_REPAIR);

      toast(`Updated ${CURRENT_REPAIR.repair.Repair_ID}`);

      BOOT.dashboard = await server('refreshDashboard');

      if(CURRENT_PAGE === 'dashboard'){
        renderDashboard(BOOT.dashboard);
      }

      if(CURRENT_PAGE === 'repairs'){
        await loadRepairs();
      }
    } catch(err){
      toast(err.message, true);
    } finally {
      showLoading(false);
    }
  }

  function detail(label,value){return `<div class="detail-item"><div class="label">${esc(label)}</div><div class="value">${value}</div></div>`}'''

if js_anchor not in text:
    raise SystemExit(
        "ERROR: Could not find the detail() JavaScript anchor. "
        "Index.html may have changed. No source file was written."
    )

text = text.replace(js_anchor, js_insert, 1)

required_markers = [
    'id="repairEditModal"',
    'onclick="openRepairEdit()"',
    'function openRepairEdit()',
    'function submitRepairEdit(e)',
    "server('updateRepair', data)",
]

missing = [marker for marker in required_markers if marker not in text]
if missing:
    raise SystemExit(
        "ERROR: Validation failed after applying edits. Missing: "
        + ", ".join(missing)
    )

path.write_text(text, encoding="utf-8")
PY

echo "Repair edit workflow added successfully."
echo

echo "------------------------------------------------------"
echo "Git diff summary"
echo "------------------------------------------------------"
git diff --stat -- "$TARGET_FILE" || true

echo
echo "------------------------------------------------------"
echo "Review the actual change"
echo "------------------------------------------------------"
echo
echo "  git diff -- "$TARGET_FILE""
echo
echo "If everything looks correct:"
echo
echo "  clasp push"
echo
echo "or use your normal deployment command."
echo
echo "To undo before committing:"
echo
echo "  cp "$BACKUP_FILE" "$TARGET_FILE""
echo
