#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Fixxir Append-Only Notes Patch
# ==========================================================
#
# Adds an audit-friendly notes timeline to already-created:
#   - Repairs
#   - Purchases
#
# Notes are appended, not overwritten. Existing record-level Notes fields
# remain intact as the original/intake note.
#
# Run from the Fixxir repo root:
#   chmod +x patch-repair-purchase-notes.sh
#   ./patch-repair-purchase-notes.sh
#   git diff --check
#   git diff -- Code.js Index.html
#   npm run deploy
# ==========================================================

CODE_FILE="${1:-Code.js}"
INDEX_FILE="${2:-Index.html}"

for f in "$CODE_FILE" "$INDEX_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f not found."
    echo "Run this patch from the Fixxir repository root."
    exit 1
  fi
done

if grep -q 'FIXXIR_ENTITY_NOTES_V1' "$CODE_FILE" && \
   grep -q 'FIXXIR_ENTITY_NOTES_UI_V1' "$INDEX_FILE"; then
  echo "Repair/Purchase notes patch is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-entity-notes-v1.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-entity-notes-v1.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" <<'PY'
from pathlib import Path
import re
import sys

code_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
html = html_path.read_text(encoding="utf-8")

def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(
            f"ERROR: Could not find anchor for {label}. "
            "Backups were created; source files were not written."
        )
    return text.replace(old, new, 1)

# ==========================================================
# Code.js — register Entity_Notes
# ==========================================================

if 'entityNotes: "Entity_Notes"' not in code:
    # Put it close to Finance/Contacts; exact location is not important.
    if '    finance: "Finance_Ledger",\n' in code:
        code = code.replace(
            '    finance: "Finance_Ledger",\n',
            '    finance: "Finance_Ledger",\n'
            '    entityNotes: "Entity_Notes",\n',
            1,
        )
    else:
        raise SystemExit("ERROR: Could not find Finance_Ledger sheet registration.")

if 'Entity_Notes: "NTE"' not in code:
    if '    Finance_Ledger: "TXN",\n' in code:
        code = code.replace(
            '    Finance_Ledger: "TXN",\n',
            '    Finance_Ledger: "TXN",\n'
            '    Entity_Notes: "NTE",\n',
            1,
        )
    else:
        raise SystemExit("ERROR: Could not find Finance_Ledger ID prefix.")

if "const FIXXIR_ENTITY_NOTE_HEADERS" not in code:
    do_get = code.find("function doGet()")
    if do_get < 0:
        raise SystemExit("ERROR: doGet() anchor not found.")

    constants = r'''
/* FIXXIR_ENTITY_NOTES_V1 */

const FIXXIR_ENTITY_NOTE_HEADERS = Object.freeze([
  "Note_ID",
  "Reference_Type",
  "Reference_ID",
  "Note_Date",
  "Note",
  "Created_At",
  "Created_By",
]);

'''
    code = code[:do_get] + constants + code[do_get:]

# Ensure sheet before required-sheet validation.
if "ensureEntityNotesSheet_(ss);" not in code:
    init_patterns = [
        "  ensureRepairDateSchema_(ss);\n",
        "  ensureProcurementSchema_(ss);\n",
        "  ensureSalesSheets_(ss);\n",
        "  ensureContactsSheet_(ss);\n",
    ]
    for anchor in init_patterns:
        if anchor in code:
            code = code.replace(
                anchor,
                anchor + "  ensureEntityNotesSheet_(ss);\n",
                1,
            )
            break
    else:
        raise SystemExit("ERROR: Could not find initializeFixxir schema anchor.")

# ==========================================================
# Code.js — include notes in Repair/Purchase detail payloads
# ==========================================================

# getRepair: inject entityNotes and return property.
repair_transactions_anchor = '''  const transactions = getRecords_(FIXXIR.sheets.finance)
'''
if "const entityNotes = getEntityNotes_(\"Repair\", id);" not in code:
    # Restrict insertion to getRepair() region.
    repair_start = code.find("function getRepair(repairId)")
    repair_end = code.find("function searchCustomers", repair_start)
    if repair_start < 0 or repair_end < 0:
        raise SystemExit("ERROR: Could not locate getRepair().")
    region = code[repair_start:repair_end]
    pos = region.find(repair_transactions_anchor)
    if pos < 0:
        raise SystemExit("ERROR: Could not find transactions inside getRepair().")
    insert_at = repair_start + pos
    code = (
        code[:insert_at]
        + '  const entityNotes = getEntityNotes_("Repair", id);\n\n'
        + code[insert_at:]
    )

# Add notes into getRepair return object after technician.
repair_start = code.find("function getRepair(repairId)")
repair_end = code.find("function searchCustomers", repair_start)
region = code[repair_start:repair_end]
if "    notes: entityNotes," not in region:
    needle = '''    technician,
    transactions,
'''
    if needle not in region:
        raise SystemExit("ERROR: Could not find getRepair() return payload anchor.")
    region = region.replace(
        needle,
        '''    technician,
    notes: entityNotes,
    transactions,
''',
        1,
    )
    code = code[:repair_start] + region + code[repair_end:]

# getPurchase: include notes.
purchase_start = code.find("function getPurchase(purchaseId)")
purchase_end = code.find("function createPurchase(payload)", purchase_start)
if purchase_start < 0 or purchase_end < 0:
    raise SystemExit("ERROR: Could not locate getPurchase().")

region = code[purchase_start:purchase_end]
if 'getEntityNotes_("Purchase", id)' not in region:
    expenses_anchor = '''  const expenses = getRecords_(FIXXIR.sheets.purchaseExpenses)
'''
    pos = region.find(expenses_anchor)
    if pos < 0:
        raise SystemExit("ERROR: Could not find purchase expenses in getPurchase().")
    # Put notes before expenses.
    region = (
        region[:pos]
        + '  const entityNotes = getEntityNotes_("Purchase", id);\n\n'
        + region[pos:]
    )

if "    notes: entityNotes," not in region:
    return_anchor = '''    items,
    expenses,
'''
    if return_anchor not in region:
        raise SystemExit("ERROR: Could not find getPurchase() return payload anchor.")
    region = region.replace(
        return_anchor,
        '''    items,
    expenses,
    notes: entityNotes,
''',
        1,
    )

code = code[:purchase_start] + region + code[purchase_end:]

# ==========================================================
# Code.js — notes backend
# ==========================================================

if "function addEntityNote(payload)" not in code:
    backend_anchor = "/* ---------------- Data helpers ---------------- */\n"
    if backend_anchor not in code:
        raise SystemExit("ERROR: Could not find Data helpers insertion anchor.")

    notes_backend = r'''
/* ---------------- Repair / Purchase Notes ---------------- */

function addEntityNote(payload) {
  assertAuthorized_();
  ensureEntityNotesSheet_(getSpreadsheet_());

  payload = payload || {};

  const referenceType = clean_(payload.Reference_Type);
  const referenceId = clean_(payload.Reference_ID);
  const note = clean_(payload.Note);

  if (!["Repair", "Purchase"].includes(referenceType)) {
    throw new Error("Notes can currently be added only to Repairs or Purchases.");
  }

  if (!referenceId) throw new Error("Reference ID is required.");
  if (!note) throw new Error("Note cannot be empty.");

  if (
    referenceType === "Repair" &&
    !findById_(FIXXIR.sheets.repairs, "Repair_ID", referenceId)
  ) {
    throw new Error("Repair not found: " + referenceId);
  }

  if (
    referenceType === "Purchase" &&
    !findById_(FIXXIR.sheets.purchases, "Purchase_ID", referenceId)
  ) {
    throw new Error("Purchase not found: " + referenceId);
  }

  const now = new Date();
  const noteId = generateId_(FIXXIR.sheets.entityNotes);

  appendRecord_(FIXXIR.sheets.entityNotes, {
    Note_ID: noteId,
    Reference_Type: referenceType,
    Reference_ID: referenceId,
    Note_Date: now,
    Note: note,
    Created_At: now,
    Created_By: currentUser_(),
  });

  return {
    ok: true,
    note: findById_(FIXXIR.sheets.entityNotes, "Note_ID", noteId),
  };
}

function getEntityNotes_(referenceType, referenceId) {
  ensureEntityNotesSheet_(getSpreadsheet_());

  return getRecords_(FIXXIR.sheets.entityNotes)
    .filter(
      (row) =>
        row.Reference_Type === referenceType &&
        row.Reference_ID === referenceId,
    )
    .sort((a, b) => {
      const dateCmp = String(b.Note_Date || "").localeCompare(
        String(a.Note_Date || ""),
      );
      if (dateCmp) return dateCmp;
      return String(b.Note_ID || "").localeCompare(String(a.Note_ID || ""));
    });
}

function ensureEntityNotesSheet_(ss) {
  ss = ss || getSpreadsheet_();

  let sh = ss.getSheetByName(FIXXIR.sheets.entityNotes);
  if (!sh) sh = ss.insertSheet(FIXXIR.sheets.entityNotes);

  const lastCol = sh.getLastColumn();

  if (!lastCol) {
    sh.getRange(1, 1, 1, FIXXIR_ENTITY_NOTE_HEADERS.length).setValues([
      FIXXIR_ENTITY_NOTE_HEADERS,
    ]);
    sh.setFrozenRows(1);
    return sh;
  }

  const existingHeaders = sh
    .getRange(1, 1, 1, lastCol)
    .getValues()[0]
    .map((header) => String(header || "").trim());

  const missing = FIXXIR_ENTITY_NOTE_HEADERS.filter(
    (header) => !existingHeaders.includes(header),
  );

  if (missing.length) {
    sh.getRange(1, lastCol + 1, 1, missing.length).setValues([missing]);
  }

  sh.setFrozenRows(1);
  return sh;
}

'''
    code = code.replace(backend_anchor, notes_backend + backend_anchor, 1)

# ==========================================================
# Index.html — shared Add Note modal
# ==========================================================

if 'id="entityNoteModal"' not in html:
    modal_anchor = '<div class="modal" id="financeModal">'
    if modal_anchor not in html:
        modal_anchor = '<div class="toast" id="toast"></div>'
    if modal_anchor not in html:
        raise SystemExit("ERROR: Could not find modal insertion point.")

    note_modal = r'''<div class="modal" id="entityNoteModal">
  <div class="modal-box" style="width:min(650px,100%)">
    <div class="modal-head">
      <h3 id="entityNoteTitle">Add Note</h3>
      <button class="close" onclick="closeModal('entityNoteModal')">×</button>
    </div>
    <form id="entityNoteForm" onsubmit="submitEntityNote(event)">
      <div class="modal-body">
        <input type="hidden" name="Reference_Type" id="entityNoteType">
        <input type="hidden" name="Reference_ID" id="entityNoteReferenceId">

        <div class="form-grid">
          <div class="full">
            <label class="required">Note</label>
            <textarea class="textarea" name="Note" id="entityNoteBody" required
              placeholder="Add an update, observation, vendor conversation, repair progress note, etc."></textarea>
          </div>
        </div>

        <div class="muted" style="font-size:12px;margin-top:10px">
          Notes are timestamped and appended to the record history. Existing notes are not overwritten.
        </div>
      </div>

      <div class="modal-foot">
        <button type="button" class="btn" onclick="closeModal('entityNoteModal')">Cancel</button>
        <button class="btn primary" type="submit">Add note</button>
      </div>
    </form>
  </div>
</div>

'''
    html = html.replace(modal_anchor, note_modal + modal_anchor, 1)

# ==========================================================
# Index.html — Repair detail
# ==========================================================

# Add button beside Edit Repair.
if "openEntityNote('Repair'" not in html:
    repair_button_patterns = [
        r'''(<button\b[^>]*onclick=["']openRepairEdit\(\)["'][^>]*>.*?</button>)''',
    ]

    matched = False
    for pattern in repair_button_patterns:
        m = re.search(pattern, html, flags=re.I | re.S)
        if m:
            addition = (
                m.group(1)
                + '\n            <button class="btn" '
                + 'onclick="openEntityNote(\'Repair\',CURRENT_REPAIR?.repair?.Repair_ID)">'
                + '+ Add Note</button>'
            )
            html = html[:m.start()] + addition + html[m.end():]
            matched = True
            break

    if not matched:
        raise SystemExit("ERROR: Could not find Edit Repair button.")

# Add Notes section before Transactions in repair detail.
repair_notes_section = r'''
      <div style="margin-top:24px" class="section-head">
        <h3>Notes</h3>
        <button class="btn small" onclick="openEntityNote('Repair',CURRENT_REPAIR?.repair?.Repair_ID)">+ Add Note</button>
      </div>
      ${entityNotesView(data.notes||[],r.Notes||'')}
'''

if "entityNotesView(data.notes||[],r.Notes||'')" not in html:
    # Handle either single or double quote formatting of Transactions heading.
    candidates = [
        '''      <div style="margin-top:24px" class="section-head"><h3>Transactions</h3></div>
''',
        '''      <div style=\"margin-top:24px\" class=\"section-head\"><h3>Transactions</h3></div>
''',
    ]

    inserted = False
    for anchor in candidates:
        if anchor in html:
            html = html.replace(anchor, repair_notes_section + anchor, 1)
            inserted = True
            break

    if not inserted:
        # Regex fallback, but only before first repair transaction table.
        m = re.search(
            r'''(?is)<div[^>]*class=["'][^"']*section-head[^"']*["'][^>]*>\s*<h3>Transactions</h3>\s*</div>''',
            html,
        )
        if not m:
            raise SystemExit("ERROR: Could not find Repair Transactions heading.")
        html = html[:m.start()] + repair_notes_section + html[m.start():]

# ==========================================================
# Index.html — Purchase detail
# ==========================================================

if "openEntityNote('Purchase'" not in html:
    # Add a button into the purchase detail header after title area, by adding
    # it inside the rendered detail body's first action-free area.
    purchase_func_start = html.find("function renderPurchaseDetail")
    if purchase_func_start < 0:
        raise SystemExit("ERROR: Could not find renderPurchaseDetail().")

    purchase_func_end = html.find("function purchaseItemsTable", purchase_func_start)
    if purchase_func_end < 0:
        raise SystemExit("ERROR: Could not find end of renderPurchaseDetail().")

    region = html[purchase_func_start:purchase_func_end]

    # Add Note button after detail-list/hero before cost box when possible.
    hero_close_anchor = '''          </div>
        </div>
        <div class="finance-box">'''
    if hero_close_anchor in region:
        region = region.replace(
            hero_close_anchor,
            '''          </div>
          <div style="margin-top:18px">
            <button class="btn" onclick="openEntityNote('Purchase',CURRENT_PURCHASE?.purchase?.Purchase_ID)">+ Add Note</button>
          </div>
        </div>
        <div class="finance-box">''',
            1,
        )
    else:
        # Simpler fallback: add button immediately before Shared costs heading.
        expenses_heading = '<div style="margin-top:24px" class="section-head"><h3>Shared costs</h3></div>'
        if expenses_heading not in region:
            raise SystemExit("ERROR: Could not find purchase detail insertion point.")
        region = region.replace(
            expenses_heading,
            '''<div style="margin-top:18px">
        <button class="btn" onclick="openEntityNote('Purchase',CURRENT_PURCHASE?.purchase?.Purchase_ID)">+ Add Note</button>
      </div>

      ''' + expenses_heading,
            1,
        )

    html = html[:purchase_func_start] + region + html[purchase_func_end:]

# Add purchase notes section before Shared costs.
if "entityNotesView(data.notes||[],p.Notes||'')" not in html:
    purchase_func_start = html.find("function renderPurchaseDetail")
    purchase_func_end = html.find("function purchaseItemsTable", purchase_func_start)
    region = html[purchase_func_start:purchase_func_end]

    heading = '<div style="margin-top:24px" class="section-head"><h3>Shared costs</h3></div>'
    if heading not in region:
        # formatted version fallback
        heading = '<div style=\\"margin-top:24px\\" class=\\"section-head\\"><h3>Shared costs</h3></div>'

    if heading not in region:
        raise SystemExit("ERROR: Could not find Purchase Shared costs heading.")

    purchase_notes = r'''<div style="margin-top:24px" class="section-head">
        <h3>Notes</h3>
        <button class="btn small" onclick="openEntityNote('Purchase',CURRENT_PURCHASE?.purchase?.Purchase_ID)">+ Add Note</button>
      </div>
      ${entityNotesView(data.notes||[],p.Notes||'')}

      '''

    region = region.replace(heading, purchase_notes + heading, 1)
    html = html[:purchase_func_start] + region + html[purchase_func_end:]

# ==========================================================
# Index.html — shared notes JS
# ==========================================================

if "function openEntityNote(referenceType,referenceId)" not in html:
    helper_anchor = "  function transactionTable(rows)"
    if helper_anchor not in html:
        # Current formatted version may use spaces.
        helper_anchor = "      function transactionTable(rows)"
    if helper_anchor not in html:
        raise SystemExit("ERROR: Could not find transactionTable() helper anchor.")

    note_js = r'''  /* FIXXIR_ENTITY_NOTES_UI_V1 */

  function openEntityNote(referenceType,referenceId){
    if(!referenceType||!referenceId){
      toast('Open a repair or purchase first.',true);
      return;
    }

    const form=document.getElementById('entityNoteForm');
    form.reset();

    document.getElementById('entityNoteType').value=referenceType;
    document.getElementById('entityNoteReferenceId').value=referenceId;
    document.getElementById('entityNoteTitle').textContent=
      `Add note · ${referenceId}`;

    document.getElementById('entityNoteModal').classList.add('open');

    setTimeout(()=>{
      document.getElementById('entityNoteBody')?.focus();
    },50);
  }

  async function submitEntityNote(e){
    e.preventDefault();
    const data=formObject(e.target);

    showLoading(true);
    try{
      await server('addEntityNote',data);
      closeModal('entityNoteModal');

      if(data.Reference_Type==='Repair'){
        CURRENT_REPAIR=await server('getRepair',data.Reference_ID);
        renderRepairDetail(CURRENT_REPAIR);
      }

      if(data.Reference_Type==='Purchase'){
        CURRENT_PURCHASE=await server('getPurchase',data.Reference_ID);
        renderPurchaseDetail(CURRENT_PURCHASE);
      }

      toast('Note added');
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

  function entityNotesView(rows,originalNote){
    const blocks=[];

    if(originalNote){
      blocks.push(`
        <div class="card section" style="margin-bottom:10px;box-shadow:none">
          <div style="display:flex;justify-content:space-between;gap:12px;margin-bottom:7px">
            <b>Original record note</b>
            <span class="muted" style="font-size:11px">Created with record</span>
          </div>
          <div>${nl2br(esc(originalNote))}</div>
        </div>`);
    }

    (rows||[]).forEach(note=>{
      blocks.push(`
        <div class="card section" style="margin-bottom:10px;box-shadow:none">
          <div style="display:flex;justify-content:space-between;gap:12px;margin-bottom:7px;flex-wrap:wrap">
            <b>${esc(note.Created_By||'Fixxir staff')}</b>
            <span class="muted" style="font-size:11px">${formatDateTime(note.Note_Date||note.Created_At)}</span>
          </div>
          <div>${nl2br(esc(note.Note||''))}</div>
        </div>`);
    });

    return blocks.length
      ? blocks.join('')
      : '<div class="empty" style="padding:16px">No notes yet.</div>';
  }

  function formatDateTime(value){
    if(!value)return '—';
    const d=new Date(value);
    if(Number.isNaN(d.getTime()))return esc(String(value));
    return d.toLocaleString('en-NG',{
      year:'numeric',
      month:'short',
      day:'2-digit',
      hour:'2-digit',
      minute:'2-digit'
    });
  }

'''
    html = html.replace(helper_anchor, note_js + helper_anchor, 1)

# ==========================================================
# Final validation
# ==========================================================

required_code = [
    'entityNotes: "Entity_Notes"',
    'Entity_Notes: "NTE"',
    'const FIXXIR_ENTITY_NOTE_HEADERS',
    'function addEntityNote(payload)',
    'function getEntityNotes_(referenceType, referenceId)',
    'function ensureEntityNotesSheet_(ss)',
    'notes: entityNotes',
]

required_html = [
    'id="entityNoteModal"',
    'function openEntityNote(referenceType,referenceId)',
    'function submitEntityNote(e)',
    'function entityNotesView(rows,originalNote)',
    "openEntityNote('Repair'",
    "openEntityNote('Purchase'",
]

missing = [x for x in required_code if x not in code] + [
    x for x in required_html if x not in html
]

if missing:
    raise SystemExit(
        "ERROR: Patch validation failed. Missing: " + ", ".join(missing)
    )

code_path.write_text(code, encoding="utf-8")
html_path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir append-only notes feature applied"
echo "======================================================"
echo
echo "Changed:"
echo "  $CODE_FILE"
echo "  $INDEX_FILE"
echo
echo "Backups:"
echo "  ${CODE_FILE}.before-entity-notes-v1.bak"
echo "  ${INDEX_FILE}.before-entity-notes-v1.bak"
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- $CODE_FILE $INDEX_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "A new Entity_Notes sheet will be created automatically."
echo "Existing Notes fields remain as the original record note."
echo "New notes are timestamped and appended, not overwritten."
