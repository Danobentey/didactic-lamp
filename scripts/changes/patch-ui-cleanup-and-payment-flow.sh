#!/usr/bin/env bash
set -euo pipefail

INDEX_FILE="${1:-Index.html}"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "ERROR: $INDEX_FILE not found."
  echo "Run this script from the Fixxir repository root."
  exit 1
fi

if grep -q 'FIXXIR_UI_CLEANUP_V1' "$INDEX_FILE"; then
  echo "UI cleanup patch already applied."
  exit 0
fi

cp "$INDEX_FILE" "${INDEX_FILE}.before-ui-cleanup-v1.bak"

python3 - "$INDEX_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
html = path.read_text(encoding="utf-8")
original = html

def remove_div_by_label(text, label_pattern, *, id_hint=None, name_hint=None):
    patterns = []
    if id_hint:
        patterns.append(
            rf'''(?ms)^[ \t]*<div(?:\s+[^>]*)?>\s*
[ \t]*<label[^>]*>[^<]*{label_pattern}[^<]*</label>\s*
.*?\bid="{re.escape(id_hint)}"[^>]*>.*?
[ \t]*</div>\s*\n?'''
        )
    if name_hint:
        patterns.append(
            rf'''(?ms)^[ \t]*<div(?:\s+[^>]*)?>\s*
[ \t]*<label[^>]*>[^<]*{label_pattern}[^<]*</label>\s*
.*?\bname="{re.escape(name_hint)}"[^>]*>.*?
[ \t]*</div>\s*\n?'''
        )
    patterns.append(
        rf'''(?m)^[ \t]*<div(?:\s+[^>]*)?><label[^>]*>[^<]*{label_pattern}[^<]*</label>.*?</div>\s*\n?'''
    )
    for pattern in patterns:
        text = re.sub(pattern, "", text, count=1)
    return text

# Repair intake
html = remove_div_by_label(html, r'Priority', id_hint='repairPriority', name_hint='Priority')
html = remove_div_by_label(html, r'Expected completion', name_hint='Expected_Completion')
html = remove_div_by_label(html, r'Quoted amount.*', name_hint='Quoted_Amount')
html = remove_div_by_label(html, r'Warranty days', name_hint='Warranty_Days')
html = remove_div_by_label(html, r'Collection method', name_hint='Collection_Method')

# Repair edit
html = remove_div_by_label(html, r'Priority', id_hint='editRepairPriority')
html = remove_div_by_label(html, r'Expected completion', id_hint='editRepairExpected')
html = remove_div_by_label(html, r'Quoted amount.*', id_hint='editRepairQuoted')
html = remove_div_by_label(html, r'Warranty days', id_hint='editRepairWarranty')
html = remove_div_by_label(html, r'Collection method', id_hint='editRepairCollection')

html = re.sub(
    r'''(?ms)^[ \t]*fillSelect\(\s*
[ \t]*'editRepairPriority'.*?
[ \t]*\);\s*\n''',
    "",
    html,
)

for pattern in [
    r"^[ \t]*fillSelect\('repairPriority'.*?\);\s*\n",
    r"^[ \t]*document\.getElementById\('editRepairPriority'\)\.value\s*=.*?;\s*\n",
    r"^[ \t]*document\.getElementById\('editRepairExpected'\)\.value\s*=.*?;\s*\n",
    r"^[ \t]*document\.getElementById\('editRepairQuoted'\)\.value\s*=\s*\n?[ \t]*.*?;\s*\n",
    r"^[ \t]*document\.getElementById\('editRepairWarranty'\)\.value\s*=\s*\n?[ \t]*.*?;\s*\n",
    r"^[ \t]*document\.getElementById\('editRepairCollection'\)\.value\s*=.*?;\s*\n",
]:
    html = re.sub(pattern, "", html, flags=re.MULTILINE)

html = re.sub(
    r'''(?m)^[ \t]*\$\{detail\('Priority',r\.Priority\|\|'—'\)\}\s*\n''',
    "",
    html,
)
html = re.sub(
    r'''(?m)^[ \t]*\$\{detail\('Expected',dateOnly\(r\.Expected_Completion\)\|\|'—'\)\}\s*\n''',
    "",
    html,
)

html = html.replace(
    '<th>Repair</th><th>Customer</th><th>Device</th><th>Status</th><th>Priority</th>',
    '<th>Repair</th><th>Customer</th><th>Device</th><th>Status</th>',
)
html = html.replace(
    "<td>${statusBadge(r.Repair_Status)}</td><td>${r.Priority==='Urgent'?'<span class=\"status urgent\">Urgent</span>':esc(r.Priority||'')}</td>",
    "<td>${statusBadge(r.Repair_Status)}</td>",
)

# SKU in sale/quote UI
html = re.sub(
    r'''(?m)^[ \t]*<div(?:\s+[^>]*)?><label>SKU</label><input[^>]*data-field="SKU"[^>]*></div>\s*\n?''',
    "",
    html,
)
html = re.sub(
    r'''(?ms)^[ \t]*<div(?:\s+[^>]*)?>\s*
[ \t]*<label>SKU</label>\s*
[ \t]*<input[^>]*(?:data-field="SKU"|name="SKU")[^>]*>\s*
[ \t]*</div>\s*\n?''',
    "",
    html,
)
html = html.replace(
    '<th>Item</th><th>SKU</th><th>IMEI / Serial</th>',
    '<th>Item</th><th>IMEI / Serial</th>',
)
html = re.sub(
    r'''(?m)^[ \t]*<td>\$\{esc\(item\.SKU\|\|''\)\}</td>\s*\n''',
    "",
    html,
)
html = html.replace(
    'Search sale, customer, IMEI, serial, SKU…',
    'Search sale, customer, IMEI or serial…',
)
html = html.replace(
    'Search quote, customer, item, SKU…',
    'Search quote, customer or item…',
)

# New Sale payment capture
html = remove_div_by_label(html, r'Initial payment.*', id_hint='saleInitialPayment', name_hint='Initial_Payment')
html = remove_div_by_label(html, r'Payment method', id_hint='salePaymentMethod')
html = remove_div_by_label(html, r'Receipt / bank reference', name_hint='Receipt_Reference')

html = re.sub(
    r'''(?m)^[ \t]*<div class="finance-row"><span>Initial payment</span><b id="salePaidView">.*?</b></div>\s*\n?''',
    "",
    html,
)
html = re.sub(
    r'''(?m)^[ \t]*<div class="finance-row"><span>Balance</span><b id="saleBalanceView">.*?</b></div>\s*\n?''',
    "",
    html,
)
html = re.sub(
    r'''(?m)^[ \t]*fillSelect\('salePaymentMethod',BOOT\.settings\.Payment_Method\|\|\[\],'Select method'\);\s*\n''',
    "",
    html,
)
html = re.sub(
    r'''(?ms)
[ \t]*const payment=num\(data\.Initial_Payment\);\s*
[ \t]*if\(payment>0&&!data\.Payment_Method\)\{\s*
[ \t]*toast\('Select a payment method for the initial payment\.',true\);\s*
[ \t]*return;\s*
[ \t]*\}\s*
''',
    "\n",
    html,
)
html = re.sub(
    r'''(?m)^[ \t]*const paid=Math\.max\(0,num\(document\.getElementById\('saleInitialPayment'\)\?\.value\)\);\s*\n''',
    "",
    html,
)
html = re.sub(
    r'''(?m)^[ \t]*const balance=Math\.max\(0,total-paid\);\s*\n''',
    "",
    html,
)
html = re.sub(
    r'''(?m)^[ \t]*if\(document\.getElementById\('salePaidView'\)\).*?;\s*\n''',
    "",
    html,
)
html = re.sub(
    r'''(?m)^[ \t]*if\(document\.getElementById\('saleBalanceView'\)\).*?;\s*\n''',
    "",
    html,
)

marker = "/* FIXXIR_UI_CLEANUP_V1 */"
if marker not in html:
    html = html.replace("</style>", f"  {marker}\n  </style>", 1)

for forbidden in [
    'id="repairPriority"',
    'id="editRepairPriority"',
    'id="editRepairExpected"',
    'id="editRepairQuoted"',
    'id="editRepairWarranty"',
    'id="editRepairCollection"',
    'id="saleInitialPayment"',
    'id="salePaymentMethod"',
]:
    if forbidden in html:
        raise SystemExit(f"ERROR: Cleanup validation failed; still found {forbidden}")

if 'id="salePaymentMethodDetail"' not in html:
    raise SystemExit("ERROR: Sale detail payment workflow was accidentally removed.")

if html == original:
    raise SystemExit("ERROR: No matching UI elements were found; no changes made.")

path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir UI cleanup applied"
echo "======================================================"
echo
echo "Changed:"
echo "  $INDEX_FILE"
echo
echo "Backup:"
echo "  ${INDEX_FILE}.before-ui-cleanup-v1.bak"
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- $INDEX_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "New Sale now creates the commercial sale first."
echo "Payments are recorded afterward from the Sale detail."
